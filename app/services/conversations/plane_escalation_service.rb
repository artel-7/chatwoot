class Conversations::PlaneEscalationService
  class ConfigurationError < StandardError; end

  MAX_MESSAGES = 40
  MAX_NAME_LENGTH = 240
  MAX_ATTACHMENTS = 20

  def initialize(conversation:, user:)
    @conversation = conversation
    @user = user
    @client = Integrations::Plane::Client.new
  end

  def perform
    raise ConfigurationError, 'Plane is not configured' unless @client.configured?

    payload = @client.create_intake_issue(
      name: issue_name,
      description_html: issue_description_html,
      priority: issue_priority
    )

    persist_escalation(payload)
    upload_attachments(payload)
    create_contact_notice
    enqueue_activity(payload)
    {
      issue_id: @client.issue_id(payload),
      identifier: @client.issue_label(payload),
      url: @client.issue_url(payload),
      status: @conversation.status,
      snoozed_until: @conversation.snoozed_until
    }
  end

  private

  def persist_escalation(payload)
    attributes = @conversation.custom_attributes.is_a?(Hash) ? @conversation.custom_attributes.dup : {}
    attributes['plane_issue_id'] = @client.issue_id(payload)
    attributes['plane_issue_identifier'] = @client.issue_label(payload)
    attributes['plane_issue_url'] = @client.issue_url(payload)
    @conversation.assign_attributes(
      custom_attributes: attributes,
      status: :snoozed,
      snoozed_until: nil
    )
    @conversation.save!
  end

  def upload_attachments(payload)
    issue_id = @client.issue_id(payload)
    return if issue_id.blank?

    attachment_records.first(MAX_ATTACHMENTS).each do |attachment|
      upload_single_attachment(issue_id, attachment)
    rescue StandardError => e
      Rails.logger.error(
        "[PlaneEscalation] attachment upload failed attachment=#{attachment.id}: #{e.class}: #{e.message}"
      )
    end
  end

  def upload_single_attachment(issue_id, attachment)
    return unless attachment.file.attached?

    blob = attachment.file.blob
    @client.upload_issue_attachment(
      issue_id: issue_id,
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      bytes: blob.download
    )
  end

  def create_contact_notice
    locale = @conversation.account.locale.presence || I18n.default_locale
    content = I18n.with_locale(locale) { I18n.t('conversations.activity.plane.contact_notice') }
    @conversation.messages.create!(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :outgoing,
      private: false,
      content: content,
      sender: @user,
      additional_attributes: { 'plane_escalation' => true }
    )
  rescue StandardError => e
    Rails.logger.error("[PlaneEscalation] contact notice failed: #{e.class}: #{e.message}")
  end

  def enqueue_activity(payload)
    identifier = @client.issue_label(payload)
    url = @client.issue_url(payload)
    content = I18n.t(
      'conversations.activity.plane.escalated',
      user_name: @user.name,
      issue_id: identifier,
      issue_url: url
    )

    Conversations::ActivityMessageJob.perform_later(
      @conversation,
      {
        account_id: @conversation.account_id,
        inbox_id: @conversation.inbox_id,
        message_type: :activity,
        content: content
      }
    )
  end

  def issue_name
    contact_name = @conversation.contact&.name.presence || 'Unknown'
    snippet = first_incoming_snippet
    title = if snippet.present?
              "[Chatwoot ##{@conversation.display_id}] #{contact_name}: #{snippet}"
            else
              "[Chatwoot ##{@conversation.display_id}] #{contact_name}"
            end
    title.truncate(MAX_NAME_LENGTH)
  end

  def first_incoming_snippet
    content = @conversation.messages.incoming.where(private: false).order(:created_at).pick(:content)
    return if content.blank?

    content.to_s.gsub(/\s+/, ' ').strip.truncate(80)
  end

  def issue_priority
    case @conversation.priority
    when 'urgent' then 'urgent'
    when 'high' then 'high'
    when 'low' then 'low'
    else 'medium'
    end
  end

  def issue_description_html
    parts = []
    parts.concat(context_attributes_html)
    parts << html_heading('Переписка')

    transcript_messages.each do |message|
      parts << "<p><strong>#{h(message_header(message))}</strong></p>"

      body = message.content.to_s.strip
      parts << "<p>#{h(body).gsub("\n", '<br>')}</p>" if body.present?

      message.attachments.each do |attachment|
        parts << attachment_html(attachment)
      end
    end

    parts.join
  end

  def context_attributes_html
    attrs = @conversation.custom_attributes
    attrs = {} unless attrs.is_a?(Hash)

    property = attrs['property'].to_s.strip
    placement = attrs['placement'].to_s.strip
    return [] if property.blank? && placement.blank?

    lines = []
    lines << "<p><strong>Property:</strong> #{h(property)}</p>" if property.present?
    lines << "<p><strong>Placement:</strong> #{h(placement)}</p>" if placement.present?
    lines
  end

  def message_header(message)
    role = message.incoming? ? 'Пользователь' : 'Агент'
    stamp = message.created_at.utc.strftime('%Y-%m-%d %H:%M UTC')
    name = short_sender_name(message.sender&.try(:name))
    return "#{stamp} · #{role}" if name.blank?

    "#{stamp} · #{role} (#{name})"
  end

  def short_sender_name(full_name)
    parts = full_name.to_s.strip.split(/\s+/).reject(&:blank?)
    return if parts.empty?
    return parts.first if parts.length == 1

    initial = parts.first.chars.first
    "#{initial}. #{parts.last}"
  end
  def attachment_html(attachment)
    name = attachment_filename(attachment)
    if attachment.external_url.present? && !attachment.file.attached?
      "<p>📎 <a href=\"#{h(attachment.external_url)}\" target=\"_blank\" rel=\"noopener noreferrer\">#{h(name)}</a></p>"
    else
      "<p>📎 #{h(name)}</p>"
    end
  end

  def attachment_filename(attachment)
    if attachment.file.attached?
      attachment.file.filename.to_s
    else
      attachment.fallback_title.presence || attachment.external_url.presence || "attachment-#{attachment.id}"
    end
  end

  def attachment_records
    Attachment
      .joins(:message)
      .merge(chat_messages_scope)
      .includes(file_attachment: :blob)
      .order('messages.created_at ASC, attachments.id ASC')
  end

  def transcript_messages
    chat_messages_scope
      .includes(:sender, { attachments: { file_attachment: :blob } })
      .order(:created_at)
      .last(MAX_MESSAGES)
      .reject { |message| service_message?(message) }
  end

  def chat_messages_scope
    @conversation.messages
                 .where(message_type: %i[incoming outgoing], private: false)
  end

  def service_message?(message)
    attrs = message.additional_attributes
    return true if attrs.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(attrs['plane_escalation'])

    content = message.content.to_s.strip
    content.blank? && message.attachments.blank?
  end

  def html_heading(text)
    "<h3>#{h(text)}</h3>"
  end

  def h(value)
    ERB::Util.html_escape(value.to_s)
  end
end

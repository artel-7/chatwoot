class Conversations::PlaneEscalationService
  class ConfigurationError < StandardError; end

  MAX_MESSAGES = 40
  MAX_NAME_LENGTH = 240

  def initialize(conversation:, user:)
    @conversation = conversation
    @user = user
    @client = Integrations::Plane::Client.new
  end

  def perform
    raise ConfigurationError, 'Plane is not configured' unless @client.configured?

    payload = @client.create_intake_issue(
      name: issue_name,
      description: issue_description,
      priority: issue_priority
    )

    persist_escalation(payload)
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

  def issue_description
    contact = @conversation.contact
    lines = [
      "Chatwoot: #{conversation_url}",
      "Contact: #{contact&.name}",
      "Email: #{contact&.email}",
      "Phone: #{contact&.phone_number}",
      "Inbox: #{@conversation.inbox&.name}",
      "Escalated by: #{@user.name}",
      '',
      'Messages:',
      ''
    ]

    transcript_messages.each do |message|
      role = message.incoming? ? 'Customer' : 'Agent'
      role = "#{role} (private)" if message.private?
      sender = message.sender&.try(:name).presence || role
      body = message.content.to_s.strip
      body = '[attachment]' if body.blank? && message.attachments.any?
      body = '[empty]' if body.blank?
      lines << "#{message.created_at.utc.iso8601} #{sender}: #{body}"
    end

    lines.join("\n")
  end

  def transcript_messages
    @conversation.messages
                 .where(message_type: %i[incoming outgoing])
                 .includes(:sender, :attachments)
                 .order(:created_at)
                 .last(MAX_MESSAGES)
  end

  def conversation_url
    "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/app/accounts/#{@conversation.account_id}/conversations/#{@conversation.display_id}"
  end
end

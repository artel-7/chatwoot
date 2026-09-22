require 'rails_helper'

RSpec.describe Conversations::PlaneEscalationService, type: :service do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }
  let(:intake_url) { 'https://plane.example/api/v1/workspaces/artel7/projects/project-1/intake-issues/' }

  before do
    stub_const('ENV', ENV.to_hash.merge(
                        'PLANE_BASE_URL' => 'https://plane.example',
                        'PLANE_API_KEY' => 'test-key',
                        'PLANE_WORKSPACE_SLUG' => 'artel7',
                        'PLANE_PROJECT_ID' => 'project-1',
                        'PLANE_PROJECT_IDENTIFIER' => 'AA',
                        'FRONTEND_URL' => 'http://localhost:3000'
                      ))
  end

  describe '#perform' do
    it 'creates a Plane intake issue with HTML transcript and stores the result' do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'Need help')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                       private: false, content: 'We are looking into it', sender: user)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                       private: true, content: 'Internal note: escalate to eng')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :activity,
                       content: 'Conversation was marked resolved by System')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :template,
                       content: 'Please rate this conversation')

      captured_body = nil
      stub_request(:post, intake_url).to_return do |request|
        captured_body = JSON.parse(request.body)
        {
          status: 201,
          headers: { 'Content-Type' => 'application/json' },
          body: {
            id: 'intake-uuid',
            issue: 'issue-uuid',
            issue_detail: {
              id: 'issue-uuid',
              sequence_id: 42,
              name: 'Need help'
            }
          }.to_json
        }
      end

      result = described_class.new(conversation: conversation, user: user).perform

      expect(result[:identifier]).to eq('AA-42')
      expect(result[:url]).to eq('https://plane.example/artel7/browse/AA-42')
      expect(result[:status]).to eq('snoozed')
      expect(conversation.reload.custom_attributes['plane_issue_id']).to eq('issue-uuid')
      expect(conversation.status).to eq('snoozed')
      expect(conversation.snoozed_until).to be_nil
      expect(conversation.messages.outgoing.last.content).to eq(
        I18n.t('conversations.activity.plane.contact_notice')
      )

      agent_parts = user.name.to_s.strip.split(/\s+/).reject(&:blank?)
      agent_label = agent_parts.length <= 1 ? agent_parts.first : "#{agent_parts.first.chars.first}. #{agent_parts.last}"

      issue = captured_body.fetch('issue')
      expect(issue).not_to have_key('description')
      html = issue.fetch('description_html')
      expect(html).to include('Need help')
      expect(html).to include('We are looking into it')
      expect(html).to include('Переписка')
      expect(html).to include('Пользователь')
      expect(html).to include("Агент (#{agent_label})")
      expect(html).not_to include('Contact')
      expect(html).not_to include('Internal note: escalate to eng')
      expect(html).not_to include('Conversation was marked resolved by System')
      expect(html).not_to include('Please rate this conversation')
      expect(a_request(:post, intake_url)).to have_been_made.once
    end

    it 'skips plane escalation notices from the transcript' do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'Need help')
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        message_type: :outgoing,
        private: false,
        content: 'Обращение передано в разработку',
        sender: user,
        additional_attributes: { 'plane_escalation' => true }
      )

      captured_body = nil
      stub_request(:post, intake_url).to_return do |request|
        captured_body = JSON.parse(request.body)
        {
          status: 201,
          headers: { 'Content-Type' => 'application/json' },
          body: {
            id: 'intake-uuid',
            issue: 'issue-uuid',
            issue_detail: { id: 'issue-uuid', sequence_id: 11 }
          }.to_json
        }
      end

      described_class.new(conversation: conversation, user: user).perform

      html = captured_body.fetch('issue').fetch('description_html')
      expect(html).to include('Need help')
      expect(html).not_to include('Обращение передано в разработку')
    end

    it 'puts property and placement at the start of the Plane description' do
      conversation.update!(
        custom_attributes: {
          'property' => 'Hotel Demo Aurora',
          'placement' => 'http://localhost:5173/reports/123',
          'subject' => 'Need help'
        }
      )
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'Need help')

      captured_body = nil
      stub_request(:post, intake_url).to_return do |request|
        captured_body = JSON.parse(request.body)
        {
          status: 201,
          headers: { 'Content-Type' => 'application/json' },
          body: {
            id: 'intake-uuid',
            issue: 'issue-uuid',
            issue_detail: { id: 'issue-uuid', sequence_id: 15 }
          }.to_json
        }
      end

      described_class.new(conversation: conversation, user: user).perform

      html = captured_body.fetch('issue').fetch('description_html')
      expect(html).to include('<p><strong>Property:</strong> Hotel Demo Aurora</p>')
      expect(html).to include('<p><strong>Placement:</strong> http://localhost:5173/reports/123</p>')
      expect(html.index('Property')).to be < html.index('Переписка')
      expect(html.index('Placement')).to be < html.index('Переписка')
    end

    it 'uploads message attachments to the Plane work item' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'see file')
      attachment = message.attachments.new(account_id: account.id, file_type: :file)
      attachment.file.attach(
        io: Rails.root.join('spec/assets/sample.pdf').open,
        filename: 'sample.pdf',
        content_type: 'application/pdf'
      )
      attachment.save!

      stub_request(:post, intake_url).to_return(
        status: 201,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          id: 'intake-uuid',
          issue: 'issue-uuid',
          issue_detail: { id: 'issue-uuid', sequence_id: 9 }
        }.to_json
      )

      credentials_url = 'https://plane.example/api/v1/workspaces/artel7/projects/project-1/work-items/issue-uuid/attachments/'
      stub_request(:post, credentials_url).to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          asset_id: 'asset-1',
          upload_data: {
            url: 'https://plane.example/plane-uploads',
            fields: {
              'key' => 'path/sample.pdf',
              'policy' => 'policy',
              'x-amz-signature' => 'sig'
            }
          }
        }.to_json
      )
      stub_request(:patch, "#{credentials_url}asset-1/").to_return(status: 204)

      expect_any_instance_of(Integrations::Plane::Client)
        .to receive(:upload_to_storage)
        .once
        .and_return(nil)

      described_class.new(conversation: conversation, user: user).perform

      expect(a_request(:post, credentials_url)).to have_been_made.once
      expect(a_request(:patch, "#{credentials_url}asset-1/").with(body: { is_uploaded: true }.to_json)).to have_been_made.once
    end

    it 'raises when Plane is not configured' do
      stub_const('ENV', ENV.to_hash.merge(
                          'PLANE_BASE_URL' => '',
                          'PLANE_API_KEY' => '',
                          'PLANE_WORKSPACE_SLUG' => '',
                          'PLANE_PROJECT_ID' => ''
                        ))

      expect do
        described_class.new(conversation: conversation, user: user).perform
      end.to raise_error(Conversations::PlaneEscalationService::ConfigurationError)
    end
  end
end

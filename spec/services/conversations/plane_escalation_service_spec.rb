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
    it 'creates a Plane intake issue and stores the result' do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'Need help')

      stub_request(:post, intake_url).to_return(
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
      )

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
      expect(a_request(:post, intake_url)).to have_been_made.once
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

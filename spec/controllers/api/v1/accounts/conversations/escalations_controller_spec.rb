require 'rails_helper'

RSpec.describe 'Conversation Escalation API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    stub_const('ENV', ENV.to_hash.merge(
                        'PLANE_BASE_URL' => 'https://plane.example',
                        'PLANE_API_KEY' => 'test-key',
                        'PLANE_WORKSPACE_SLUG' => 'artel7',
                        'PLANE_PROJECT_ID' => 'project-1',
                        'PLANE_PROJECT_IDENTIFIER' => 'AA',
                        'FRONTEND_URL' => 'http://localhost:3000'
                      ))
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/{id}/escalation' do
    it 'returns unauthorized when the user is not authenticated' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/escalation", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates a Plane intake issue' do
      stub_request(:post, 'https://plane.example/api/v1/workspaces/artel7/projects/project-1/intake-issues/')
        .to_return(
          status: 201,
          headers: { 'Content-Type' => 'application/json' },
          body: { id: 'intake-uuid', issue: 'issue-uuid', issue_detail: { id: 'issue-uuid', sequence_id: 7 } }.to_json
        )

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/escalation",
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['identifier']).to eq('AA-7')
      expect(response.parsed_body['status']).to eq('snoozed')
      expect(conversation.reload.status).to eq('snoozed')
    end
  end
end

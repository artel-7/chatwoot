require 'rails_helper'

RSpec.describe 'Video Materials API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/video_materials' do
    it 'returns unauthorized when the user is not authenticated' do
      get "/api/v1/accounts/#{account.id}/video_materials"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists uploaded videos' do
      video = create(:video_material, account: account, title: 'Onboarding')

      get "/api/v1/accounts/#{account.id}/video_materials",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['title']).to eq('Onboarding')
      expect(response.parsed_body.first['description']).to eq('Short overview of the main screens')
      expect(response.parsed_body.first['url']).to include("/videos/#{video.token}")
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/video_materials' do
    it 'uploads a video and returns a public url' do
      file = fixture_file_upload(Rails.root.join('spec/assets/sample.mp4'), 'video/mp4')

      post "/api/v1/accounts/#{account.id}/video_materials",
           params: { title: 'Guide', description: 'How to start', file: file },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['title']).to eq('Guide')
      expect(response.parsed_body['description']).to eq('How to start')
      expect(response.parsed_body['url']).to include('/videos/')
      expect(account.video_materials.count).to eq(1)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/video_materials/{id}' do
    it 'updates the video description' do
      video = create(:video_material, account: account, title: 'Guide')

      patch "/api/v1/accounts/#{account.id}/video_materials/#{video.id}",
            params: { description: 'Updated overview' },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['description']).to eq('Updated overview')
      expect(video.reload.description).to eq('Updated overview')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/video_materials/{id}' do
    it 'deletes the video' do
      video = create(:video_material, account: account)

      delete "/api/v1/accounts/#{account.id}/video_materials/#{video.id}",
             headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(VideoMaterial.find_by(id: video.id)).to be_nil
    end
  end
end

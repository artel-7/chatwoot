class Api::V1::Accounts::Conversations::EscalationsController < Api::V1::Accounts::Conversations::BaseController
  def create
    result = Conversations::PlaneEscalationService.new(
      conversation: @conversation,
      user: Current.user
    ).perform

    render json: result, status: :ok
  rescue Conversations::PlaneEscalationService::ConfigurationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Integrations::Plane::Client::RequestError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end

class Integrations::Plane::Client
  def initialize
    @base_url = ENV.fetch('PLANE_BASE_URL', '').to_s.chomp('/')
    @api_key = ENV.fetch('PLANE_API_KEY', '').to_s
    @workspace_slug = ENV.fetch('PLANE_WORKSPACE_SLUG', '').to_s
    @project_id = ENV.fetch('PLANE_PROJECT_ID', '').to_s
  end

  def configured?
    [@base_url, @api_key, @workspace_slug, @project_id].all?(&:present?)
  end

  def create_intake_issue(name:, description:, priority:)
    raise ArgumentError, 'Plane is not configured' unless configured?

    response = HTTParty.post(
      intake_url,
      headers: {
        'X-API-Key' => @api_key,
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      },
      body: {
        issue: {
          name: name,
          description: description,
          priority: priority
        }
      }.to_json
    )

    parsed = parse_body(response)
    unless response.success?
      message = parsed.is_a?(Hash) ? (parsed['detail'] || parsed['error'] || parsed['message'] || parsed.to_json) : response.body
      raise Integrations::Plane::Client::RequestError, message.to_s
    end

    parsed
  end

  def issue_url(payload)
    issue = issue_from(payload)
    return @base_url if issue.blank?

    identifier = browse_identifier(issue)
    return "#{@base_url}/#{@workspace_slug}/browse/#{identifier}" if identifier.present?

    issue_id = issue['id']
    return @base_url if issue_id.blank?

    "#{@base_url}/#{@workspace_slug}/projects/#{@project_id}/issues/#{issue_id}"
  end

  def issue_label(payload)
    issue = issue_from(payload)
    browse_identifier(issue).presence || issue&.[]('id').to_s
  end

  def issue_id(payload)
    issue_from(payload)&.[]('id')
  end

  class RequestError < StandardError; end

  private

  def intake_url
    "#{@base_url}/api/v1/workspaces/#{@workspace_slug}/projects/#{@project_id}/intake-issues/"
  end

  def parse_body(response)
    body = response.parsed_response
    return body if body.is_a?(Hash)

    JSON.parse(response.body)
  rescue JSON::ParserError
    {}
  end

  def issue_from(payload)
    return {} unless payload.is_a?(Hash)

    detail = payload['issue_detail']
    return detail if detail.is_a?(Hash)

    issue = payload['issue']
    return issue if issue.is_a?(Hash)

    return { 'id' => issue } if issue.present?

    {}
  end

  def browse_identifier(issue)
    sequence_id = issue['sequence_id']
    project_identifier = ENV.fetch('PLANE_PROJECT_IDENTIFIER', '').to_s
    project_identifier = issue.dig('project_detail', 'identifier').to_s if project_identifier.blank?
    return if sequence_id.blank? || project_identifier.blank?

    "#{project_identifier}-#{sequence_id}"
  end
end

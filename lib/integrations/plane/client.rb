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

  def create_intake_issue(name:, description_html:, priority:)
    raise ArgumentError, 'Plane is not configured' unless configured?

    response = HTTParty.post(
      intake_url,
      headers: json_headers,
      body: {
        issue: {
          name: name,
          description_html: description_html,
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

  def upload_issue_attachment(issue_id:, filename:, content_type:, bytes:)
    raise ArgumentError, 'Plane is not configured' unless configured?
    raise ArgumentError, 'issue_id is required' if issue_id.blank?
    raise ArgumentError, 'filename is required' if filename.blank?
    raise ArgumentError, 'bytes are required' if bytes.nil?

    size = bytes.bytesize
    credentials = request_attachment_credentials(
      issue_id: issue_id,
      filename: filename,
      content_type: content_type,
      size: size
    )
    upload_to_storage(
      credentials: credentials,
      bytes: bytes,
      content_type: content_type,
      filename: filename
    )
    complete_attachment_upload(issue_id: issue_id, asset_id: credentials['asset_id'])
    credentials
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

  def json_headers
    {
      'X-API-Key' => @api_key,
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def intake_url
    "#{@base_url}/api/v1/workspaces/#{@workspace_slug}/projects/#{@project_id}/intake-issues/"
  end

  def attachment_url(issue_id)
    "#{@base_url}/api/v1/workspaces/#{@workspace_slug}/projects/#{@project_id}/work-items/#{issue_id}/attachments/"
  end

  def attachment_complete_url(issue_id, asset_id)
    "#{attachment_url(issue_id)}#{asset_id}/"
  end

  def request_attachment_credentials(issue_id:, filename:, content_type:, size:)
    response = HTTParty.post(
      attachment_url(issue_id),
      headers: json_headers,
      body: {
        name: filename,
        type: content_type.presence || 'application/octet-stream',
        size: size,
        external_source: 'chatwoot'
      }.to_json
    )
    parsed = parse_body(response)
    unless response.success?
      message = parsed.is_a?(Hash) ? (parsed['detail'] || parsed['error'] || parsed['message'] || parsed.to_json) : response.body
      raise Integrations::Plane::Client::RequestError, message.to_s
    end
    raise Integrations::Plane::Client::RequestError, 'Plane attachment credentials missing upload_data' if parsed['upload_data'].blank?
    raise Integrations::Plane::Client::RequestError, 'Plane attachment credentials missing asset_id' if parsed['asset_id'].blank?

    parsed
  end

  def upload_to_storage(credentials:, bytes:, content_type:, filename:)
    require 'net/http/post/multipart'
    require 'tempfile'

    upload_data = credentials['upload_data']
    fields = (upload_data['fields'] || {}).transform_keys(&:to_s)
    mime = content_type.presence || fields['Content-Type'].presence || 'application/octet-stream'
    safe_name = File.basename(filename.to_s).presence || 'attachment.bin'
    uri = URI.parse(upload_data['url'].to_s)

    Tempfile.create(['plane-upload', File.extname(safe_name)]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      file.rewind

      params = {}
      fields.each { |key, value| params[key] = value }
      params['file'] = UploadIO.new(file, mime, safe_name)

      request = Net::HTTP::Post::Multipart.new(uri, params)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      response = http.request(request)
      return if response.is_a?(Net::HTTPSuccess) || response.code.to_i == 204

      raise Integrations::Plane::Client::RequestError,
            "Plane storage upload failed: HTTP #{response.code} #{response.body.to_s.truncate(200)}"
    end
  end

  def complete_attachment_upload(issue_id:, asset_id:)
    response = HTTParty.patch(
      attachment_complete_url(issue_id, asset_id),
      headers: json_headers,
      body: { is_uploaded: true }.to_json
    )
    return if response.success? || response.code == 204

    parsed = parse_body(response)
    message = parsed.is_a?(Hash) ? (parsed['detail'] || parsed['error'] || parsed['message'] || parsed.to_json) : response.body
    raise Integrations::Plane::Client::RequestError, message.to_s
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

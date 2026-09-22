class VideoMaterialsController < ApplicationController
  layout 'video_library'

  def index
    @videos = VideoMaterial.order(created_at: :desc)
  end

  def show
    @video = VideoMaterial.find_by(token: params[:token])
    render_not_found && return if @video.blank? || !@video.file.attached?
  end

  def file
    video = VideoMaterial.find_by(token: params[:token])
    render_not_found && return if video.blank? || !video.file.attached?

    blob = video.file.blob
    expires_in 1.year, public: true
    send_file blob.service.path_for(blob.key),
              type: blob.content_type,
              disposition: 'inline',
              filename: blob.filename.to_s
  end

  private

  def render_not_found
    render file: Rails.public_path.join('404.html').to_s, status: :not_found, layout: false
  end
end

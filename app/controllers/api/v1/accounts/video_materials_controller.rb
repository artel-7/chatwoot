class Api::V1::Accounts::VideoMaterialsController < Api::V1::Accounts::BaseController
  before_action :fetch_video_material, only: [:update, :destroy]

  def index
    videos = Current.account.video_materials.order(created_at: :desc)
    render json: videos.map(&:as_api_json)
  end

  def create
    video = Current.account.video_materials.new(user: Current.user)
    video.title = params[:title].to_s.strip
    video.description = params[:description].to_s.strip
    video.file.attach(params[:file]) if params[:file].present?
    video.save!
    render json: video.as_api_json, status: :ok
  end

  def update
    @video_material.title = params[:title].to_s.strip if params.key?(:title)
    @video_material.description = params[:description].to_s.strip if params.key?(:description)
    @video_material.save!
    render json: @video_material.as_api_json
  end

  def destroy
    @video_material.destroy!
    head :ok
  end

  private

  def fetch_video_material
    @video_material = Current.account.video_materials.find(params[:id])
  end
end

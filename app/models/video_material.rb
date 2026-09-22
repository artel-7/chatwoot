class VideoMaterial < ApplicationRecord
  ALLOWED_CONTENT_TYPES = %w[
    video/mp4
    video/webm
    video/ogg
    video/quicktime
    video/x-matroska
    video/x-msvideo
  ].freeze
  MAX_FILE_SIZE = 1.gigabyte

  belongs_to :account
  belongs_to :user, optional: true
  has_one_attached :file

  before_validation :ensure_token
  before_validation :sync_file_metadata

  validates :title, presence: true
  validates :token, presence: true, uniqueness: true
  validate :validate_file

  def public_url
    "#{frontend_base}/videos/#{token}"
  end

  def file_url
    "#{frontend_base}/videos/#{token}/file"
  end

  def as_api_json
    {
      id: id,
      title: title,
      description: description,
      token: token,
      url: public_url,
      file_url: file_url,
      content_type: content_type,
      byte_size: byte_size,
      created_at: created_at
    }
  end

  private

  def ensure_token
    self.token = SecureRandom.urlsafe_base64(16) if token.blank?
  end

  def sync_file_metadata
    return unless file.attached?

    self.content_type = file.content_type if file.content_type.present?
    self.byte_size = file.byte_size if file.byte_size.present?
    self.title = file.filename.to_s if title.blank?
  end

  def validate_file
    unless file.attached?
      errors.add(:file, 'must be attached')
      return
    end

    type = file.content_type.to_s
    unless ALLOWED_CONTENT_TYPES.include?(type) || type.start_with?('video/')
      errors.add(:file, 'must be a video')
    end

    return if file.byte_size.blank? || file.byte_size <= MAX_FILE_SIZE

    errors.add(:file, 'is too large')
  end

  def frontend_base
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end
end

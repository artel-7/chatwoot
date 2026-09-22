# frozen_string_literal: true

FactoryBot.define do
  factory :video_material do
    account
    title { 'Product walkthrough' }
    description { 'Short overview of the main screens' }

    after(:build) do |video|
      video.file.attach(
        io: StringIO.new('fake-video-bytes'),
        filename: 'walkthrough.mp4',
        content_type: 'video/mp4'
      )
    end
  end
end

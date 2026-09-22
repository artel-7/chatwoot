class AddDescriptionToVideoMaterials < ActiveRecord::Migration[7.1]
  def change
    add_column :video_materials, :description, :text
  end
end

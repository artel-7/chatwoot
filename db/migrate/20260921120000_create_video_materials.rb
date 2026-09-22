class CreateVideoMaterials < ActiveRecord::Migration[7.1]
  def change
    create_table :video_materials do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :title, null: false
      t.string :token, null: false
      t.string :content_type
      t.bigint :byte_size
      t.timestamps
    end

    add_index :video_materials, :token, unique: true
  end
end

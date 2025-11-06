class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :display_name
      t.integer :age
      t.string :gender
      t.text :bio
      t.string :looking_for_gender
      t.integer :min_age
      t.integer :max_age
      t.integer :discovery_radius_km
      t.boolean :share_location

      t.timestamps
    end
  end
end

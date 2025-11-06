class CreateLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :likes do |t|
      t.references :liker, null: false, foreign_key: { to_table: :users }
      t.references :liked, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :likes, [:liker_id, :liked_id], unique: true
  end
end

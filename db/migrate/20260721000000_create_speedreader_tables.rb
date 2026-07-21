class CreateSpeedreaderTables < ActiveRecord::Migration[7.0]
  def change
    create_table :speedreader_books do |t|
      t.integer :user_id, null: false
      t.string :title, null: false
      t.string :author
      t.integer :page_count, default: 0
      t.integer :word_count, default: 0
      t.integer :upload_id
      t.jsonb :words, null: false, default: []
      t.jsonb :pages, null: false, default: []
      t.timestamps
    end
    add_index :speedreader_books, :user_id

    create_table :speedreader_progress do |t|
      t.integer :user_id, null: false
      t.integer :book_id, null: false
      t.integer :word_index, default: 0
      t.integer :wpm
      t.timestamps
    end
    add_index :speedreader_progress, [:user_id, :book_id], unique: true
  end
end

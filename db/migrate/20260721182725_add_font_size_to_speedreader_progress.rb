class AddFontSizeToSpeedreaderProgress < ActiveRecord::Migration[6.1]
  def change
    add_column :speedreader_progress, :font_size, :decimal, precision: 4, scale: 2, default: 2.6, null: false
  end
end

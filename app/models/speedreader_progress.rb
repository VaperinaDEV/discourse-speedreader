class SpeedreaderProgress < ActiveRecord::Base
  self.table_name = "speedreader_progress"

  belongs_to :user
  belongs_to :book, class_name: "SpeedreaderBook", foreign_key: :book_id
end

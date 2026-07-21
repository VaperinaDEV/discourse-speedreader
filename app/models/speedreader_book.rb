class SpeedreaderBook < ActiveRecord::Base
  self.table_name = "speedreader_books"

  belongs_to :user
  belongs_to :upload, optional: true
  has_many :progresses,
           class_name: "SpeedreaderProgress",
           foreign_key: :book_id,
           dependent: :destroy
end

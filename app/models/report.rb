class Report < ApplicationRecord
  belongs_to :reporter, class_name: 'User', optional: true

  has_many_attached :photos

  validates :description, presence: true
end

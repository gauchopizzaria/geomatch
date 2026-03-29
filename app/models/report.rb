class Report < ApplicationRecord
  belongs_to :reporter, class_name: 'User', optional: true

  has_many_attached :photos

  validates :description, presence: true

  scope :pending,  -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  def resolved?
    resolved_at.present?
  end

  def resolve!
    update!(resolved_at: Time.current)
  end
end

class Report < ApplicationRecord

    # Permite anexar várias fotos à denúncia
  has_many_attached :photos
  
  validates :description, presence: true
end

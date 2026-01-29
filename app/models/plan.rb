class Plan < ApplicationRecord
  monetize :price_cents

  has_many :payments, dependent: :nullify
  has_many :users, dependent: :nullify

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_currency, presence: true
  validates :duration_days, presence: true, numericality: { only_integer: true, greater_than: 0 }

  validates :features, presence: true
  validate :features_must_be_a_hash

  def feature_enabled?(key)
    features[key.to_s] == true
  end

  def feature_value(key, default: nil)
    features.fetch(key.to_s, default)
  end

  private

  def features_must_be_a_hash
    errors.add(:features, "must be a JSON object") unless features.is_a?(Hash)
  end
end



class Payment < ApplicationRecord
  include PaymentStateMachine

  belongs_to :plan
  belongs_to :user

  scope :latest_first, -> { order(created_at: :desc) }

  def amount
    plan.price
  end

  def apply_premium!(fallback_days: 30)
    effective_days = plan.duration_days.presence || fallback_days

    now = Time.current
    base = [user.premium_until, now].compact.max
    user.update!(premium_until: base + effective_days.days)
  end
end



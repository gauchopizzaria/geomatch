module PaymentStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    aasm column: :state do
      state :created, initial: true
      state :pending
      state :approved
      state :rejected
      state :refunded

      event :pending do
        transitions from: %i[created], to: :pending, after: Proc.new { |*args| update_payment_with_mp_payment(*args) }
      end

      event :approve do
        transitions from: %i[created pending], to: :approved, after: Proc.new { |*args| set_approve(*args) }
      end

      event :reject do
        transitions from: %i[created pending], to: :rejected, after: Proc.new { |*args| update_payment_with_mp_payment(*args) }
      end

      event :refund do
        transitions from: %i[approved rejected], to: :refunded, after: Proc.new { |*args| update_payment_with_mp_payment(*args) }
      end
    end
  end

  def set_approve(mp_payment)
    update_payment_with_mp_payment(mp_payment)
    sync_user_plan_from_payment!
  end

  def set_refund(mp_payment)
    update_payment_with_mp_payment(mp_payment)
    touch(:paid_at)
    sync_user_plan_from_refund!
  end

  def update_payment_with_mp_payment(mp_payment)
    update!(
      mercado_pago_payment_id: mp_payment["id"]&.to_s,
      mercado_pago_merchant_order_id: mp_payment["order"]&.dig("id")&.to_s,
      mercado_pago_payload: mp_payment
    )
  end

  private

  def sync_user_plan_from_payment!
    user.update!(plan: plan, premium_until: Time.current + plan.duration_days.days)
  end

  def sync_user_plan_from_refund!
    free_plan = Plan.find_by(name: 'Free')
    return if user.plan_id == free_plan.id

    user.update!(plan: free_plan, premium_until: nil)
  end
end



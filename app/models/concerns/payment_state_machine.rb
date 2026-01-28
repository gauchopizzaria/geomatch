module PaymentStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    aasm column: :state do
      state :created, initial: true
      state :pending
      state :authorized
      state :in_process
      state :in_mediation
      state :approved
      state :rejected
      state :cancelled
      state :refunded
      state :charged_back

      event :mark_pending do
        transitions from: %i[created], to: :pending
      end

      event :mark_authorized do
        transitions from: %i[created pending in_process], to: :authorized
      end

      event :mark_in_process do
        transitions from: %i[created pending authorized], to: :in_process
      end

      event :approve do
        transitions from: %i[created pending authorized in_process in_mediation], to: :approved
        after do
          touch(:paid_at)
          sync_user_plan_from_payment!
        end
      end

      event :reject do
        transitions from: %i[created pending authorized in_process in_mediation], to: :rejected
      end

      event :cancel do
        transitions from: %i[created pending authorized in_process in_mediation], to: :cancelled
      end

      event :refund do
        transitions from: %i[approved], to: :refunded
      end

      event :chargeback do
        transitions from: %i[approved refunded], to: :charged_back
      end
    end
  end

  def sync_user_plan_from_payment!
    return if user.plan_id == plan_id

    user.update!(plan: plan)
  end

  def mark_from_mercado_pago!(mp_payment:)
    mp_status = (mp_payment["status"] || mp_payment[:status] || state).to_s
    self.mercado_pago_payment_id = (mp_payment["id"] || mp_payment[:id])&.to_s
    self.mercado_pago_merchant_order_id = (mp_payment["order"]&.dig("id") || mp_payment.dig(:order, :id))&.to_s
    self.mercado_pago_payload = mp_payment

    transition_from_mp_status!(mp_status)

    self.paid_at ||= Time.current if approved?
  end

  private

  def transition_from_mp_status!(mp_status)
    # Mercado Pago statuses: approved, pending, in_process, authorized, in_mediation,
    # rejected, cancelled, refunded, charged_back
    case mp_status
    when "approved"
      approve! if may_approve?
    when "pending"
      mark_pending! if may_mark_pending?
    when "in_process"
      mark_in_process! if may_mark_in_process?
    when "authorized"
      mark_authorized! if may_mark_authorized?
    when "in_mediation"
      self.state = "in_mediation" unless aasm.current_state == :in_mediation
    when "rejected"
      reject! if may_reject?
    when "cancelled"
      cancel! if may_cancel?
    when "refunded"
      refund! if may_refund?
    when "charged_back"
      chargeback! if may_chargeback?
    else
      # mantém como está
    end
  end
end



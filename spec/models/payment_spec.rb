require "rails_helper"

RSpec.describe Payment, type: :model do
  subject(:payment) { build(:payment) }

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:plan) }
  end

  describe "state machine (AASM)" do
    it "starts in created state" do
      payment.save!
      expect(payment.state).to eq("created")
      expect(payment).to be_created
    end

    it "when approved, sets paid_at and updates user's plan" do
      old_plan = create(:plan, :free)
      new_plan = create(:plan)
      user = create(:user, plan: old_plan)

      pay = Payment.create!(user: user, plan: new_plan)
      pay.approve!

      expect(pay.reload.state).to eq("approved")
      expect(pay.paid_at).to be_present
      expect(user.reload.plan).to eq(new_plan)
    end

    it "mark_from_mercado_pago! transitions to approved based on mp status" do
      old_plan = create(:plan, :free)
      new_plan = create(:plan)
      user = create(:user, plan: old_plan)
      pay = Payment.create!(user: user, plan: new_plan)

      pay.mark_from_mercado_pago!(mp_payment: { "status" => "approved", "id" => 123 })

      expect(pay.reload.state).to eq("approved")
      expect(pay.paid_at).to be_present
      expect(user.reload.plan).to eq(new_plan)
      expect(pay.mercado_pago_payment_id).to eq("123")
    end
  end
end



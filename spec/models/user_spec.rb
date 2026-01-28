require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  describe "associations" do
    it { is_expected.to belong_to(:plan) }
    it { is_expected.to have_many(:payments).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:plan) }
  end

  describe "callbacks" do
    it "sets free plan by default on create when plan is nil (if free exists)" do
      free_plan = create(:plan, :free)
      new_user = build(:user, plan: nil)
      new_user.save!
      expect(new_user.plan).to eq(free_plan)
    end
  end

  describe "#premium?" do
    it "returns true when premium_until is in the future" do
      user.premium_until = 1.day.from_now
      expect(user.premium?).to be(true)
    end

    it "returns false when premium_until is nil or in the past" do
      user.premium_until = nil
      expect(user.premium?).to be(false)
      user.premium_until = 1.day.ago
      expect(user.premium?).to be(false)
    end
  end
end



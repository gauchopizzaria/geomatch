class CreateFreePlanAndSetDefaultForUsers < ActiveRecord::Migration[8.1]
  class MigrationPlan < ApplicationRecord
    self.table_name = "plans"
  end

  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    MigrationPlan.reset_column_information
    MigrationUser.reset_column_information

    free_attrs = {
      code: "free",
      name: "Free",
      price_cents: 0,
      price_currency: "BRL",
      duration_days: 36500,
      active: true,
      description: "Plano gratuito",
      features: {
        "unlimited_likes" => false,
        "see_who_liked" => false,
        "super_likes_per_day" => 0
      }
    }

    free_plan = MigrationPlan.find_or_initialize_by(code: "free")
    free_plan.assign_attributes(free_attrs.except(:code))
    free_plan.save!

    MigrationUser.where(plan_id: nil).update_all(plan_id: free_plan.id)
  end
end



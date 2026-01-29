class PlansController < ApplicationController
  before_action :authenticate_user!

  def index
    @plans = Plan.where(active: true).order(price_cents: :asc)
  end
end



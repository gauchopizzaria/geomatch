# app/controllers/push_subscriptions_controller.rb
class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:create, :destroy] # Pode ser necessário para PWA

  def create
    subscription_params = params.require(:push_subscription).permit(:endpoint, :p256dh, :auth)
    
    @subscription = current_user.push_subscriptions.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    @subscription.assign_attributes(subscription_params)

    if @subscription.save
      head :ok
    else
      render json: @subscription.errors, status: :unprocessable_entity
    end
  end

  def destroy
    @subscription = current_user.push_subscriptions.find_by(endpoint: params[:endpoint])
    if @subscription&.destroy
      head :ok
    else
      head :not_found
    end
  end
end
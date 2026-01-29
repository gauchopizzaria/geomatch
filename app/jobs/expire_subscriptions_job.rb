class ExpireSubscriptionsJob
  include Sidekiq::Job

  def perform
    User.expired_premium.find_each do |user|
      user.downgrade_to_free!
    end
  end
end

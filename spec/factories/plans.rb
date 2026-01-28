FactoryBot.define do
  factory :plan do
    sequence(:code) { |n| "premium_#{n}" }
    name { "Plano Premium" }

    price_cents { 2990 }
    price_currency { "BRL" }

    features do
      {
        "unlimited_likes" => true,
        "see_who_liked" => true,
        "super_likes_per_day" => 5
      }
    end

    duration_days { 30 }
    active { true }
    description { Faker::Lorem.sentence }

    trait :free do
      code { "free" }
      name { "Free" }
      price_cents { 0 }
      duration_days { 36500 }
      features do
        {
          "unlimited_likes" => false,
          "see_who_liked" => false,
          "super_likes_per_day" => 0
        }
      end
    end
  end
end



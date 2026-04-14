# frozen_string_literal: true

FactoryBot.define do
  factory :reply_bridge_alias do
    association :server
    sequence(:email) { |n| "person#{n}@example.com" }
  end
end

FactoryBot.define do
  factory :olx_location do
    external_id { 1 }
    name { "MyString" }
    country_id { 1 }
    state_id { 1 }
    canton_id { 1 }
    lat { "9.99" }
    lon { "9.99" }
    zip_code { "MyString" }
  end
end

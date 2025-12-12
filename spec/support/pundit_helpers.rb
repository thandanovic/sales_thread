# Custom RSpec matchers for Pundit policy testing
module PunditHelpers
  extend RSpec::Matchers::DSL

  # Matcher to check if a policy permits an action
  matcher :permit_action do |action|
    match do |policy|
      policy.public_send("#{action}?")
    end

    failure_message do |policy|
      "Expected #{policy.class} to permit #{action} for #{policy.user&.email || 'guest'}"
    end

    failure_message_when_negated do |policy|
      "Expected #{policy.class} to forbid #{action} for #{policy.user&.email || 'guest'}"
    end
  end

  # Alias for readability
  matcher :forbid_action do |action|
    match do |policy|
      !policy.public_send("#{action}?")
    end

    failure_message do |policy|
      "Expected #{policy.class} to forbid #{action} for #{policy.user&.email || 'guest'}"
    end

    failure_message_when_negated do |policy|
      "Expected #{policy.class} to permit #{action} for #{policy.user&.email || 'guest'}"
    end
  end
end

RSpec.configure do |config|
  config.include PunditHelpers, type: :policy
end

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.frame_ancestors :none
  end
end
# frozen_string_literal: true

# NOTE: Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before(0, Rack::Cors) do
  allow do
    origins URI(ENV['LAGO_FRONT_URL']).host

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head]
  end
end

# frozen_string_literal: true

# NOTE: Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before(0, Rack::Cors) do
  allow do
    if Rails.env.development?
      origins 'app.lago.dev'
    elsif ENV['LAGO_FRONT_URL']
      origins URI(ENV['LAGO_FRONT_URL']).host
    end

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head]
  end
end

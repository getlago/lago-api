# frozen_string_literal: true

namespace :signup do
  desc 'This task seeds lago with an organisation & a user for on premise deployment'
  task seed_organization: :environment do
    if ENV['LAGO_CREATE_ORG'].present? && ENV['LAGO_CREATE_ORG'] == 'true'
      puts '[SEED] Setting up default Organization'

      unless ENV['LAGO_ORG_USER_PASSWORD'].present? &&
          ENV['LAGO_ORG_USER_EMAIL'].present?
        raise "Couldn't find required LAGO_ORG_USER_PASSWORD, LAGO_ORG_USER_EMAIL environment variables"
      end

      user = User.create_with(password: ENV['LAGO_ORG_USER_PASSWORD'])
        .find_or_create_by!(email: ENV['LAGO_ORG_USER_EMAIL'])

      # Ideally, we should force the org primary key so we can use it in other services
      # (like for inbound webhooks url using stripe CLI, or for other webhook endpoints)
      organization = if ENV['LAGO_ORG_ID'].present?
        Organization.create_with(name: ENV.fetch('LAGO_ORG_NAME', 'Lago Dev Env'))
          .find_or_create_by!(id: ENV.fetch('LAGO_ORG_ID'))
      else
        Organization.find_or_create_by!(name: ENV.fetch('LAGO_ORG_NAME', 'Lago Dev Env'))
      end

      Membership.find_or_create_by!(user:, organization:, role: :admin)

      if ENV['LAGO_ORG_API_KEY'].present?
        api_key = ApiKey.find_or_create_by!(organization:, value: ENV['LAGO_ORG_API_KEY'])
        api_key.update!(value: ENV['LAGO_ORG_API_KEY'])
      else
        ApiKey.find_or_create_by!(organization:)
      end

      puts "[SEED] Organization #{organization.id} is now set up"
    end
  end

  task :setup_stripe, [:name] => :environment do |_task, args|
    if ENV['STRIPE_API_KEY'].blank? || ENV['LAGO_ORG_ID'].blank?
      raise "STRIPE_API_KEY and LAGO_ORG_ID environment variables are required"
    end

    name = args[:name] || "Stripe"
    code = name.downcase.strip.tr(' ', '_').gsub(/[^\w-]/, '')

    result = ::PaymentProviders::StripeService.new
      .create_or_update(
        code:,
        name:,
        secret_key: ENV['STRIPE_API_KEY'],
        success_redirect_url: ENV['LAGO_API_URL'],
      )

    result.success? ? 0 : 123
  end
end

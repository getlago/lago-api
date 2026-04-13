# frozen_string_literal: true

class AddSlugToOrganizations < ActiveRecord::Migration[8.0]
  RESERVED_SLUGS = %w[
    auth login sign-up forgot-password reset-password invitation
    customer-portal 404 forbidden api admin graphql webhooks google okta
    settings new design-system devtool
    customers customer plans plan invoices invoice subscriptions
    coupons coupon add-ons add-on billable-metrics billable-metric
    credit-notes analytics analytics-v2 forecasts payments payment
    features feature tax webhook api-keys create update duplicate
  ].freeze

  SLUG_FORMAT = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/

  def up
    safety_assured do
      add_column :organizations, :slug, :string

      Organization.unscoped.find_each do |org|
        candidate = generate_slug_for(org.name)
        candidate = resolve_collision(candidate)
        org.update_column(:slug, candidate) # rubocop:disable Rails/SkipsModelValidations
      end

      change_column_null :organizations, :slug, false
    end
  end

  def down
    remove_column :organizations, :slug # rubocop:disable Lago/NoDropColumnOrTable
  end

  private

  def generate_slug_for(name)
    candidate = ActiveSupport::Inflector.transliterate(name.to_s)
      .parameterize
      .tr("_", "-")
      .truncate(40, omission: "")

    if candidate.length < 3 || candidate.match?(/\A\d+\z/) || RESERVED_SLUGS.include?(candidate)
      generate_random_slug
    else
      candidate
    end
  end

  def resolve_collision(slug)
    return slug unless slug_taken?(slug)

    if slug.start_with?("org-") && slug.length == 9
      generate_random_slug
    else
      loop do
        candidate = "#{slug.truncate(36, omission: "")}-#{SecureRandom.alphanumeric(3).downcase}"
        return candidate unless slug_taken?(candidate)
      end
    end
  end

  def generate_random_slug
    loop do
      candidate = "org-#{SecureRandom.alphanumeric(5).downcase}"
      return candidate unless slug_taken?(candidate)
    end
  end

  def slug_taken?(slug)
    Organization.unscoped.where(slug: slug).exists?
  end
end

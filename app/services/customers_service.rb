# frozen_string_literal: true

class CustomersService < BaseService
  def create_from_api(organization:, params:)
    customer = organization.customers.find_or_initialize_by(customer_id: params[:customer_id])

    customer.name = params[:name]
    customer.country = params[:country]&.upcase
    customer.address_line1 = params[:address_line1]
    customer.address_line2 = params[:address_line2]
    customer.state = params[:state]
    customer.zipcode = params[:zipcode]
    customer.email = params[:email]
    customer.city = params[:city]
    customer.url = params[:url]
    customer.phone = params[:phone]
    customer.logo_url = params[:logo_url]
    customer.legal_name = params[:legal_name]
    customer.legal_number = params[:legal_number]
    customer.vat_rate = params[:vat_rate] if params.key?(:vat_rate)
    customer.save!

    result.customer = customer
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  def create(**args)
    customer = Customer.create!(
      organization_id: args[:organization_id],
      customer_id: args[:customer_id],
      name: args[:name],
      country: args[:country]&.upcase,
      address_line1: args[:address_line1],
      address_line2: args[:address_line2],
      state: args[:state],
      zipcode: args[:zipcode],
      email: args[:email],
      city: args[:city],
      url: args[:url],
      phone: args[:phone],
      logo_url: args[:logo_url],
      legal_name: args[:legal_name],
      legal_number: args[:legal_number],
      vat_rate: args[:vat_rate],
    )

    result.customer = customer
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  def update(**args)
    customer = result.user.customers.find_by(id: args[:id])
    return result.fail!('not_found') unless customer

    customer.name = args[:name]
    customer.country = args[:country]&.upcase
    customer.address_line1 = args[:address_line1]
    customer.address_line2 = args[:address_line2]
    customer.state = args[:state]
    customer.zipcode = args[:zipcode]
    customer.email = args[:email]
    customer.city = args[:city]
    customer.url = args[:url]
    customer.phone = args[:phone]
    customer.logo_url = args[:logo_url]
    customer.legal_name = args[:legal_name]
    customer.legal_number = args[:legal_number]
    customer.vat_rate = args[:vat_rate] if args.key?(:vat_rate)

    # NOTE: Only name is editable if customer is attached to subscriptions
    customer.customer_id = args[:customer_id] unless customer.attached_to_subscriptions?
    customer.save!

    result.customer = customer
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  def destroy(id:)
    customer = result.user.customers.find_by(id: id)
    return result.fail!('not_found') unless customer

    unless customer.deletable?
      return result.fail!(
        'forbidden',
        'Customer is attached to an active subscription',
      )
    end

    customer.destroy!

    result.customer = customer
    result
  end
end

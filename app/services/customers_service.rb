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

    customer.name = args[:name] if args.key?(:name)
    customer.country = args[:country]&.upcase if args.key?(:country)
    customer.address_line1 = args[:address_line1] if args.key?(:address_line1)
    customer.address_line2 = args[:address_line2] if args.key?(:address_line2)
    customer.state = args[:state] if args.key?(:state)
    customer.zipcode = args[:zipcode] if args.key?(:zipcode)
    customer.email = args[:email] if args.key?(:email)
    customer.city = args[:city] if args.key?(:city)
    customer.url = args[:url] if args.key?(:url)
    customer.phone = args[:phone] if args.key?(:phone)
    customer.logo_url = args[:logo_url] if args.key?(:logo_url)
    customer.legal_name = args[:legal_name] if args.key?(:legal_name)
    customer.legal_number = args[:legal_number] if args.key?(:legal_number)
    customer.vat_rate = args[:vat_rate] if args.key?(:vat_rate)

    # NOTE: Customer_id is not editable if customer is attached to subscriptions
    if !customer.attached_to_subscriptions? && args.key?(:customer_id)
      customer.customer_id = args[:customer_id]
    end

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

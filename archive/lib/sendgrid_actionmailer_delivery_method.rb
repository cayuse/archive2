require 'sendgrid-ruby'

class SendgridActionmailerDeliveryMethod
  include SendGrid

  attr_accessor :settings

  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    sg = SendGrid::API.new(api_key: settings[:api_key])
    
    # Create the email
    from = Email.new(mail.from.first)
    to = Email.new(mail.to.first)
    subject = mail.subject
    content = Content.new(type: 'text/html', value: mail.body.raw_source)
    
    # Create the mail object
    sendgrid_mail = Mail.new(from, subject, to, content)
    
    # Add text content if available
    if mail.text_part
      text_content = Content.new(type: 'text/plain', value: mail.text_part.body.raw_source)
      sendgrid_mail.add_content(text_content)
    end
    
    # Send the email
    response = sg.client.mail._('send').post(request_body: sendgrid_mail.to_json)
    
    # Raise error if delivery failed
    if response.status_code.to_i >= 400
      raise "SendGrid delivery failed: #{response.status_code} - #{response.body}"
    end
    
    response
  end
end

# Register the delivery method with ActionMailer
ActionMailer::Base.add_delivery_method :sendgrid_actionmailer, SendgridActionmailerDeliveryMethod 
class Portal::PasswordController < PortalController

# WARNING: modifying this file is not recommended unless you are familiar with
# developing for the Ruby on Rails web application framework!
#
# This class handles the password change splash portal for new tenants.
# Once password is changed successfully, the account is moved to the active tenant group.

  # Override the index action to show password change form
  def index
    if logged_in?
      # User is already authenticated, check if password needs to be changed
      if @current_account.scratch&.include?('password_change_required')
        render_portal_partial('password_change_form')
      else
        # Password already changed, redirect to main portal
        redirect_to_main_portal
      end
    else
      # Show login form for password change
      render_portal_partial('password_change_login')
    end
  end

  # Handle password change submission
  def change_password
    return unless logged_in?

    old_password = params[:old_password].to_s
    new_password = params[:new_password].to_s
    confirm_password = params[:confirm_password].to_s

    # Validate passwords
    if new_password.blank?
      flash.now[:error] = :password_cannot_be_blank
      render_portal_partial('password_change_form')
      return
    end

    if new_password != confirm_password
      flash.now[:error] = :passwords_do_not_match
      render_portal_partial('password_change_form')
      return
    end

    if new_password.length < 8
      flash.now[:error] = :password_too_short
      render_portal_partial('password_change_form')
      return
    end

    # Verify old password if this is a password change (not initial setup)
    unless @current_account.scratch&.include?('initial_password_setup')
      unless @current_account.authenticate(old_password)
        flash.now[:error] = :invalid_current_password
        render_portal_partial('password_change_form')
        return
      end
    end

    # Update the password
    begin
      @current_account.update!(
        password: new_password,
        password_confirmation: new_password,
        scratch: nil  # Clear the password change requirement flag
      )

      # Move user to active tenant group
      move_to_active_tenant_group

      flash[:success] = :password_changed_successfully
      redirect_to_main_portal
    rescue => e
      flash.now[:error] = :password_update_failed
      render_portal_partial('password_change_form')
    end
  end

  private

  def move_to_active_tenant_group
    # Find the active tenant group
    active_group = Group.find_by(name: 'Active Tenants') || Group.find_by(name: 'Residents')
    
    if active_group
      # Remove from current groups and add to active tenant group
      @current_account.groups.clear
      @current_account.groups << active_group
      @current_account.save!
      
      # Log the group change
      Rails.logger.info "Account #{@current_account.login} moved to #{active_group.name} group after password change"
    else
      Rails.logger.warn "Active tenant group not found for account #{@current_account.login}"
    end
  end

  def redirect_to_main_portal
    # Redirect to the main Fairmont portal
    redirect_to "#{request.protocol}#{request.host}/portal/fairmanage/"
  end

end
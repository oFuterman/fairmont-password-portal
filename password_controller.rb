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
      if account_needs_password_change?(@current_account)
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

  # Handle token-based account setup auto-login
  def account_setup
    token = params[:token]
    
    # Validate token exists
    if token.blank?
      flash[:error] = :invalid_or_missing_token
      redirect_to action: :index
      return
    end

    # Find account by token
    account = find_account_by_token(token)
    
    if account.nil?
      flash[:error] = :invalid_or_expired_token
      redirect_to action: :index
      return
    end

    # Auto-login the user
    self.login_session = login_session_for_account(account)
    
    # Clear the token (single-use security)
    clear_account_setup_token(account)
    
    # Redirect to password change form with success message
    flash[:success] = :auto_login_successful
    redirect_to action: :index
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
    unless is_initial_password_setup?(@current_account)
      unless @current_account.authenticate(old_password)
        flash.now[:error] = :invalid_current_password
        render_portal_partial('password_change_form')
        return
      end
    end

    # Update the password
    begin
      # Clear password change requirement from scratch field
      clear_password_change_requirement(@current_account)
      
      @current_account.update!(
        password: new_password,
        password_confirmation: new_password
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

  def account_needs_password_change?(account)
    return false unless account.scratch.present?
    
    # Check if scratch contains password_change_required flag
    if account.scratch.include?('password_change_required')
      return true
    end
    
    # Also check YAML parsed data for more structured approach
    begin
      data = YAML.load(account.scratch)
      return false unless data.is_a?(Hash)
      return !!(data[:password_change_required] || data['password_change_required'])
    rescue
      return false
    end
  end

  def is_initial_password_setup?(account)
    return false unless account.scratch.present?
    
    # Check if this is initial setup (no old password verification needed)
    if account.scratch.include?('initial_password_setup')
      return true
    end
    
    # For token-based setup, consider it initial setup
    begin
      data = YAML.load(account.scratch)
      return false unless data.is_a?(Hash)
      return !!(data[:initial_password_setup] || data['initial_password_setup'] || 
                data[:auto_login_token] || data['auto_login_token'])
    rescue
      return false
    end
  end

  def clear_password_change_requirement(account)
    return unless account.scratch.present?
    
    begin
      data = YAML.load(account.scratch)
      data = {} unless data.is_a?(Hash)
    rescue
      data = {}
    end
    
    # Remove password change requirement flags
    data.delete(:password_change_required)
    data.delete('password_change_required')
    data.delete(:initial_password_setup)
    data.delete('initial_password_setup')
    
    # Update scratch field
    if data.empty?
      account.scratch = nil
    else
      account.scratch = data.to_yaml
    end
    
    account.save!
  end

  def find_account_by_token(token)
    # Search through all accounts to find matching token
    Account.all.find do |account|
      next unless account.scratch.present?
      
      # Parse YAML data from scratch field
      begin
        data = YAML.load(account.scratch)
        data = {} unless data.is_a?(Hash)
      rescue
        data = {}
      end
      
      # Check both string and symbol keys for compatibility
      stored_token = data[:auto_login_token] || data['auto_login_token']
      expires_at = data[:token_expires_at] || data['token_expires_at']
      
      if stored_token == token
        # Check if token is still valid (not expired)
        if expires_at
          begin
            expiry_time = expires_at.is_a?(String) ? Time.parse(expires_at) : expires_at
            if expiry_time > Time.now
              return account
            else
              # Token expired, clear it
              clear_account_setup_token(account)
            end
          rescue
            # Invalid expiry date, treat as expired
            clear_account_setup_token(account)
          end
        end
      end
    end
    nil
  end

  def clear_account_setup_token(account)
    return unless account.scratch.present?
    
    # Parse existing scratch data
    begin
      data = YAML.load(account.scratch)
      data = {} unless data.is_a?(Hash)
    rescue
      data = {}
    end
    
    # Remove token-related keys (both string and symbol versions)
    data.delete(:auto_login_token)
    data.delete('auto_login_token')
    data.delete(:token_expires_at)
    data.delete('token_expires_at')
    
    # Update scratch field - set to nil if empty, otherwise save updated YAML
    if data.empty?
      account.scratch = nil
    else
      account.scratch = data.to_yaml
    end
    
    begin
      account.save!
      Rails.logger.info "Cleared account setup token for account #{account.login}"
    rescue => e
      Rails.logger.error "Failed to clear token for account #{account.login}: #{e.message}"
    end
  end

end
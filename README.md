# Fairmont Password Change Portal

This is a specialized splash portal for new Fairmont tenants that requires them to change their password before accessing the main portal.

## Workflow

1. **New tenants** are assigned to the "Initial Setup" user group
2. They are redirected to this password change portal 
3. After successfully changing their password, they are automatically moved to the "Active Tenants" user group
4. They are then redirected to the main Fairmont portal

## Features

- **Secure password validation** with strength indicator
- **Responsive design** that works on all devices
- **Automatic group transition** after password change
- **Clean, modern interface** with Fairmont branding
- **Form validation** with helpful error messages

## Files

- `password_controller.rb` - Main controller logic for password changes and group transitions
- `views/index.erb` - Main template that routes to appropriate view
- `views/_password_change_login.erb` - Login form for initial authentication
- `views/_password_change_form.erb` - Password change form with validation
- `stylesheets/password_portal.scss.erb` - Modern styling with Fairmont colors

## Configuration Required in rXg

### User Groups
1. **Initial Setup** - For new tenants (points to this portal)
2. **Active Tenants** - For tenants with changed passwords (points to main portal)

### Policies
- Initial Setup group should have a policy that redirects to this password portal
- Active Tenants group should have a policy that redirects to the main fairmanage portal

### Custom Portal Setup
- Controller Name: `password`
- Portal Source: Git
- Repository URL: `https://github.com/YOUR_USERNAME/fairmont-password-portal.git`
- Sync Frequency: 15 minutes
- Restart after sync: Yes

## Account Setup for New Tenants

When creating accounts for new tenants:
1. Set their `scratch` field to include `password_change_required`
2. Assign them to the "Initial Setup" user group
3. Give them a temporary password

Example:
```ruby
account = Account.create!(
  login: "tenant123",
  password: "temp_password_123",
  scratch: "password_change_required",
  # other fields...
)

initial_group = Group.find_by(name: 'Initial Setup')
account.groups << initial_group
```
require_relative "../test_helper"

class Test::AdminUi::TestApiUsersApiKeyVisibility < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTestHelpers::AdminAuth
  include ApiUmbrellaTestHelpers::Setup

  def setup
    setup_server
  end

  def test_api_key_in_create_notification
    @user = FactoryGirl.create(:xss_api_user)
    admin_login
    visit "/admin/#/api_users/new"

    fill_in "E-mail", :with => "example@example.com"
    fill_in "First Name", :with => "John"
    fill_in "Last Name", :with => "Doe"
    check "User agrees to the terms and conditions"
    click_button("Save")

    assert_content("Successfully saved the user")
    user = ApiUser.order_by(:created_at.asc).last
    assert_equal("Doe", user.last_name)
    assert_content(user.api_key)
  end

  def test_api_key_can_be_revealed_when_admin_has_permissions
    admin = FactoryGirl.create(:admin)
    user = FactoryGirl.create(:api_user, :created_by => admin.id, :created_at => Time.now.utc - 2.weeks + 5.minutes)
    admin_login(admin)
    visit "/admin/#/api_users/#{user.id}/edit"

    assert_content(user.api_key_preview)
    refute_content(user.api_key)
    assert_link("(reveal)")
    click_link("(reveal)")
    assert_content(user.api_key)
    refute_content(user.api_key_preview)
    refute_link("(reveal)")
    assert_link("(hide)")
    click_link("(hide)")
    assert_content(user.api_key_preview)
    refute_content(user.api_key)
    assert_link("(reveal)")
  end

  def test_api_key_is_hidden_when_admin_lacks_permissions
    admin = FactoryGirl.create(:limited_admin)
    user = FactoryGirl.create(:api_user, :created_by => admin.id, :created_at => Time.now.utc - 2.weeks - 5.minutes)
    admin_login(admin)
    visit "/admin/#/api_users/#{user.id}/edit"

    assert_content(user.api_key_preview)
    refute_content(user.api_key)
    refute_link("(reveal)")
  end
end

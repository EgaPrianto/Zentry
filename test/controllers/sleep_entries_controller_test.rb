require "test_helper"

class SleepEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sleep_entry = sleep_entries(:one)
  end

  test "should get index" do
    get sleep_entries_url, as: :json
    assert_response :success
  end

  test "should create sleep_entry" do
    assert_difference("SleepEntry.count") do
      post sleep_entries_url, params: { sleep_entry: {} }, as: :json
    end

    assert_response :created
  end

  test "should show sleep_entry" do
    get sleep_entry_url(@sleep_entry), as: :json
    assert_response :success
  end

  test "should update sleep_entry" do
    patch sleep_entry_url(@sleep_entry), params: { sleep_entry: {} }, as: :json
    assert_response :success
  end

  test "should destroy sleep_entry" do
    assert_difference("SleepEntry.count", -1) do
      delete sleep_entry_url(@sleep_entry), as: :json
    end

    assert_response :no_content
  end
end

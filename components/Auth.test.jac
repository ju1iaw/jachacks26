test "email-only seeker credential is stable and normalized" {
    assert (
        seeker_email_credential("  Person@Example.COM ")
        == seeker_email_credential("person@example.com")
    );
    assert len(seeker_email_credential("person@example.com")) >= 8;
}

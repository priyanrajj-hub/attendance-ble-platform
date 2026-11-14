import pytest
from app.services.challenge_service import ChallengeService


TEST_VECTORS = [
    {
        "session_secret": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        "session_id": "550e8400-e29b-41d4-a716-446655440000",
        "step": 58000000,
        "expected_challenge": "3a7bb516e37fe7d07c3d9d400e404434",
    },
    {
        "session_secret": "a7f92b4c81d3e5f60123456789abcdefa7f92b4c81d3e5f60123456789abcdef",
        "session_id": "e2e00000-0000-0000-0000-000000000001",
        "step": 100000000,
        "expected_challenge": "a5ff3c823f09f3eee7d34ea41b13c80c",
    },
    {
        "session_secret": "deadbeefcafebabe0123456789abcdefdeadbeefcafebabe0123456789abcdef",
        "session_id": "77777777-8888-9999-aaaa-bbbbccccdddd",
        "step": 999999999,
        "expected_challenge": "323214f238d073724db658924c7142e2",
    },
]


def test_challenge_crypto_test_vectors():
    """
    Verifies that ChallengeService in Python produces bit-for-bit identical outputs
    to the Flutter ChallengeCrypto implementation across all standard test vectors.
    """
    for vec in TEST_VECTORS:
        derived = ChallengeService.compute_challenge(
            vec["session_secret"],
            vec["session_id"],
            vec["step"],
        )
        assert derived == vec["expected_challenge"]
        assert len(derived) == 32  # Exactly 128 bits of entropy

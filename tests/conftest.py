import pytest

@pytest.fixture()
def user(accounts):
    return accounts.add("a4b5bb916ca53954496315445795441332c377f2845a1326b8cad3ffc9b97c41")

@pytest.fixture()
def ppcontract(PPContract, user):
    return PPContract.deploy("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", "0xc00e94Cb662C3520282E6f5717214004A7f26888", {"from": user})

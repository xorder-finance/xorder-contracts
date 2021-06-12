import pytest

@pytest.fixture()
def user(accounts):
    return accounts.add("a4b5bb916ca53954496315445795441332c377f2845a1326b8cad3ffc9b97c41")

@pytest.fixture()
def ppcontract(PPContract, user):
    return PPContract.deploy("0x5eAe89DC1C671724A672ff0630122ee834098657", "0xc00e94Cb662C3520282E6f5717214004A7f26888", {"from": user})

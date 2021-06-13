import pytest

@pytest.fixture()
def comptroller(interface):
    return interface.ComptrollerInterface("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B")

@pytest.fixture()
def comp(interface):
    return interface.CErc20Interface("0xc00e94Cb662C3520282E6f5717214004A7f26888")

@pytest.fixture()
def limitOrderProtocolMock(LimitOrderProtocolMock, accounts):
    return LimitOrderProtocolMock.deploy({"from": accounts[0]})

@pytest.fixture()
def ppcontract(PPContract, comptroller, comp, limitOrderProtocolMock, accounts):
    return PPContract.deploy(comptroller, comp, limitOrderProtocolMock, {"from": accounts[0]})
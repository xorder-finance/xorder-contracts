def test_kek(ppcontract, accounts):
    ppcontract.makeMoney({"from": accounts[0]})
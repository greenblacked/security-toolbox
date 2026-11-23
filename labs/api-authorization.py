"""Verify tenant-aware object authorization using a local policy and synthetic data."""

import unittest
from dataclasses import dataclass


@dataclass(frozen=True)
class Principal:
    user_id: str
    tenant_id: str
    can_update: bool = False


@dataclass
class Order:
    tenant_id: str
    owner_id: str
    status: str = "open"


class OrderService:
    def __init__(self):
        self._orders = {
            "order-a": Order("north", "alice"),
            "order-b": Order("south", "bob"),
        }

    def _visible_order(self, principal, order_id):
        order = self._orders.get(order_id)
        if (
            order is None
            or order.tenant_id != principal.tenant_id
            or order.owner_id != principal.user_id
        ):
            return None
        return order

    def read(self, principal, order_id):
        order = self._visible_order(principal, order_id)
        return (200, order.status) if order is not None else (404, None)

    def cancel(self, principal, order_id):
        order = self._visible_order(principal, order_id)
        if order is None:
            return 404
        if not principal.can_update:
            return 403
        order.status = "canceled"
        return 204


class TestOrderAuthorization(unittest.TestCase):
    def setUp(self):
        self.service = OrderService()
        self.alice = Principal("alice", "north", can_update=True)
        self.bob = Principal("bob", "south", can_update=True)

    def test_owner_can_read_and_update(self):
        self.assertEqual(self.service.read(self.alice, "order-a"), (200, "open"))
        self.assertEqual(self.service.cancel(self.alice, "order-a"), 204)
        self.assertEqual(self.service.read(self.alice, "order-a"), (200, "canceled"))

    def test_cross_tenant_matches_unknown_order(self):
        self.assertEqual(self.service.read(self.alice, "order-b"), (404, None))
        self.assertEqual(self.service.read(self.alice, "unknown"), (404, None))
        self.assertEqual(self.service.cancel(self.alice, "order-b"), 404)
        self.assertEqual(self.service.cancel(self.alice, "unknown"), 404)
        self.assertEqual(self.service.read(self.bob, "order-b"), (200, "open"))

    def test_same_tenant_non_owner_is_denied(self):
        teammate = Principal("chris", "north", can_update=True)
        self.assertEqual(self.service.read(teammate, "order-a"), (404, None))
        self.assertEqual(self.service.cancel(teammate, "order-a"), 404)
        self.assertEqual(self.service.read(self.alice, "order-a"), (200, "open"))

    def test_owner_without_write_permission_cannot_mutate(self):
        reader = Principal("alice", "north")
        self.assertEqual(self.service.read(reader, "order-a"), (200, "open"))
        self.assertEqual(self.service.cancel(reader, "order-a"), 403)
        self.assertEqual(self.service.read(self.alice, "order-a"), (200, "open"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.core.models import Employee

User = get_user_model()


def make_employee(username: str, role: str, **flags) -> Employee:
    user = User.objects.create_user(username=username, password="x-test-pass-1")
    return Employee.objects.create(user=user, name=username, role=role, **flags)


class EmployeeCapabilitiesTests(TestCase):
    def test_smm_gets_only_content(self):
        smm = make_employee("smm", Employee.Role.SMM)
        caps = smm.capabilities
        self.assertTrue(caps["content"])
        # Orders, payments, shifts and menu stay closed for a plain SMM.
        self.assertFalse(caps["wait"])
        self.assertFalse(caps["bar"])
        self.assertFalse(caps["kitchen"])
        self.assertFalse(caps["menu"])
        self.assertFalse(caps["manage"])

    def test_smm_with_granted_extras(self):
        smm = make_employee("smm2", Employee.Role.SMM, can_wait=True)
        caps = smm.capabilities
        self.assertTrue(caps["content"])
        self.assertTrue(caps["wait"])
        self.assertFalse(caps["menu"])

    def test_boss_roles_have_content(self):
        for role in (Employee.Role.MANAGER, Employee.Role.ADMIN):
            with self.subTest(role=role):
                boss = make_employee(f"boss-{role}", role)
                self.assertTrue(boss.capabilities["content"])

    def test_floor_and_station_roles_have_no_content(self):
        for role in (Employee.Role.WAITER, Employee.Role.KITCHEN, Employee.Role.BAR):
            with self.subTest(role=role):
                worker = make_employee(f"worker-{role}", role)
                self.assertFalse(worker.capabilities["content"])

    def test_can_content_flag_grants_content_to_any_role(self):
        waiter = make_employee("waiter-content", Employee.Role.WAITER, can_content=True)
        caps = waiter.capabilities
        self.assertTrue(caps["content"])
        self.assertTrue(caps["wait"])
        self.assertFalse(caps["manage"])

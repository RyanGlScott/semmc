from django.db import models

class User(models.Model):
    username = models.CharField(max_length=64, unique=True)

class Arch(models.Model):
    name = models.CharField(max_length=64, unique=True)

class Host(models.Model):
    hostname = models.CharField(max_length=128, unique=True)
    arch = models.ForeignKey(Arch, on_delete=models.CASCADE)

class Batch(models.Model):
    fuzzer_host = models.CharField(max_length=128)
    testing_host = models.ForeignKey(Host, on_delete=models.CASCADE)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    submitted_at = models.DateTimeField(auto_now_add=True)

class Opcode(models.Model):
    name = models.CharField(max_length=128)
    arch = models.ForeignKey(Arch, on_delete=models.CASCADE)

class TestSuccess(models.Model):
    batch = models.ForeignKey(Batch, on_delete=models.CASCADE)
    opcode = models.ForeignKey(Opcode, on_delete=models.CASCADE)
    count = models.IntegerField()

class TestFailure(models.Model):
    batch = models.ForeignKey(Batch, on_delete=models.CASCADE)
    opcode = models.ForeignKey(Opcode, on_delete=models.CASCADE)
    pretty = models.CharField(max_length=256)
    arguments = models.TextField()

class TestFailureState(models.Model):
    test_failure = models.ForeignKey(TestFailure, on_delete=models.CASCADE)
    location = models.CharField(max_length=128)
    expected_value = models.CharField(max_length=256)
    actual_value = models.CharField(max_length=256)
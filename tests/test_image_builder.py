# Tests for EC2 Image Builder module
# Validates the image builder infrastructure and component definitions

import json
import os
import pytest
import subprocess


class TestImageBuilderModule:
    """Test EC2 Image Builder module structure and validation."""

    def test_terraform_validate(self, tmp_path):
        """Test that the image builder module validates successfully."""
        terraform_path = tmp_path / "terraform"
        terraform_path.mkdir()

        # Copy image builder module
        src = "terraform/image-builder"
        subprocess.run(
            ["cp", "-r", src, str(terraform_path)],
            check=True,
            capture_output=True,
        )

        # Initialize and validate
        subprocess.run(
            ["terraform", "init", "-backend=false"],
            cwd=str(terraform_path),
            check=True,
            capture_output=True,
        )

        result = subprocess.run(
            ["terraform", "validate"],
            cwd=str(terraform_path),
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, f"Validation failed: {result.stderr}"

    def test_image_builder_has_components(self):
        """Test that all required components are defined."""
        components_dir = "terraform/image-builder/components"
        expected_components = [
            "al2023_hardening.yaml",
            "slurm_build.yaml",
            "munge.yaml",
            "node_exporter.yaml",
            "cloudwatch_agent.yaml",
        ]

        for component in expected_components:
            path = os.path.join(components_dir, component)
            assert os.path.exists(path), f"Component {component} not found"

    def test_image_builder_has_main_tf(self):
        """Test that main.tf exists with required resources."""
        main_tf_path = "terraform/image-builder/main.tf"
        assert os.path.exists(main_tf_path), "main.tf not found"

        with open(main_tf_path) as f:
            content = f.read()

        required_resources = [
            "aws_imagebuilder_component",
            "aws_imagebuilder_image_recipe",
            "aws_imagebuilder_infrastructure_configuration",
            "aws_imagebuilder_image_pipeline",
            "aws_ssm_parameter",
            "aws_kms_key",
        ]

        for resource in required_resources:
            assert resource in content, f"Resource {resource} not found in main.tf"

    def test_image_builder_has_components_in_recipe(self):
        """Test that the recipe includes all components."""
        main_tf_path = "terraform/image-builder/main.tf"

        with open(main_tf_path) as f:
            content = f.read()

        required_components = [
            "al2023_hardening",
            "slurm_build",
            "munge",
            "node_exporter",
            "cloudwatch_agent",
        ]

        for component in required_components:
            assert (
                f"component_arn = aws_imagebuilder_component.{component}.arn"
                in content
            ), f"Component {component} not in recipe"

    def test_image_builder_has_ssm_parameters(self):
        """Test that SSM parameters for AMI tracking are defined."""
        main_tf_path = "terraform/image-builder/main.tf"

        with open(main_tf_path) as f:
            content = f.read()

        assert '/hpc-testbed/ami/compute/current' in content
        assert '/hpc-testbed/ami/compute/previous' in content

    def test_image_builder_has_weekly_schedule(self):
        """Test that the pipeline has a weekly schedule."""
        main_tf_path = "terraform/image-builder/main.tf"

        with open(main_tf_path) as f:
            content = f.read()

        assert "cron(0 2 ? * SUN *)" in content, "Weekly schedule not found"

    def test_image_builder_has_kms_key(self):
        """Test that KMS key for AMI encryption is defined."""
        main_tf_path = "terraform/image-builder/main.tf"

        with open(main_tf_path) as f:
            content = f.read()

        assert "aws_kms_key" in content
        assert "ami_encryption" in content

    def test_components_have_valid_yaml(self):
        """Test that component YAML files are valid."""
        components_dir = "terraform/image-builder/components"

        for filename in os.listdir(components_dir):
            if filename.endswith('.yaml'):
                path = os.path.join(components_dir, filename)
                with open(path) as f:
                    content = f.read()

                # Basic YAML structure checks
                assert "version:" in content, f"version not found in {filename}"
                assert "name:" in content, f"name not found in {filename}"
                assert "steps:" in content or "components:" in content, f"steps or components not found in {filename}"

    def test_image_builder_has_iam_role(self):
        """Test that IAM role and instance profile are defined."""
        main_tf_path = "terraform/image-builder/main.tf"

        with open(main_tf_path) as f:
            content = f.read()

        assert "aws_iam_role" in content
        assert "aws_iam_instance_profile" in content

    def test_image_builder_outputs(self):
        """Test that required outputs are defined."""
        main_tf_path = "terraform/image-builder/main.tf"

        with open(main_tf_path) as f:
            content = f.read()

        required_outputs = [
            "image_recipe_arn",
            "image_pipeline_arn",
            "infrastructure_configuration_arn",
            "ami_ssm_parameter_current",
            "ami_ssm_parameter_previous",
            "image_builder_role_arn",
            "kms_key_arn",
        ]

        for output in required_outputs:
            assert f'output "{output}"' in content, f"Output {output} not found"

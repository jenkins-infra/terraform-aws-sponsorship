moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2025-jdk8"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2025-jdk8"]
}
moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2025-jdk11"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2025-jdk11"]
}
moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2025-jdk17"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2025-jdk17"]
}
moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2025-jdk21"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2025-jdk21"]
}
moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2025-jdk25"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2025-jdk25"]
}
moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2025-infratest-jdk21"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2025-infratest-jdk21"]
}
moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2022-jdk21"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2022-jdk21"]
}
moved {
  from = aws_autoscaling_group.ci_jenkins_io_ec2_agents["windows_2019-jdk21"]
  to   = aws_autoscaling_group.ci_jenkins_io_ec2_agents["spot-windows_2019-jdk21"]
}

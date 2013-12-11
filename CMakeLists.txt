INSTALL(PROGRAMS
  bin/pipeline_functions.pm

  bin/standard_pipeline.pl
  
  bin/lobe_volumes_qc.pl
  bin/obj2_bet.pl
  bin/pipeline_classify.pl
  bin/pipeline_correct.pl
  bin/pipeline_dbm.pl
  bin/pipeline_deface_grid.pl
  bin/pipeline_deface.pl
  bin/pipeline_em_classify.pl
  bin/pipeline_face.pl
  bin/pipeline_iccmask_stx.pl
  bin/pipeline_jacobian.pl
  bin/pipeline_launch_all_pve.pl
  bin/pipeline_launch_all_segment.pl
  bin/pipeline_launch_all_smooth.pl
  bin/pipeline_launch_pve.pl
  bin/pipeline_longitudinal.pl
  bin/pipeline_mritotal.pl
  bin/pipeline_nlr.pl
  bin/pipeline_pd_t1.pl
  bin/pipeline_pve.pl
  bin/pipeline_qc_face.pl
  bin/pipeline_qc_mask.pl
  bin/pipeline_qc_nl.pl
  bin/pipeline_qc.pl
  bin/pipeline_qc_reg.pl
  bin/pipeline_qc_t1w.pl
  bin/pipeline_qc_t2t1.pl
  bin/pipeline_relx_cls.pl
  bin/pipeline_relx.pl
  bin/pipeline_segment.pl
  bin/pipeline_smooth.pl
  bin/pipeline_t1t2_cls.pl
  bin/pipeline_t2tot1.pl
  bin/pipeline_tal_mask.pl
  bin/pipeline_talnoscale.pl
  bin/pipeline_thomas.pl
  bin/pipeline_volumes_lin.pl
  bin/pipeline_volumes_nl.pl
  bin/pipeline_watermark.pl

  DESTINATION pipeline )

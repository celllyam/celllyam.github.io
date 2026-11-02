---
title: "Oracle Database - RAC"
date: 2026-11-01T00:00:00+09:00
draft: false
description: ""   # 1절 한 줄 결론을 다 쓴 뒤 채우기
Categories: ["실무 회고"]
Tags: ["Oracle", "RAC", "Application Continuity", "Transaction Guard", "고가용성"]
---

 - Abbreviation
 - RAC(Real Application Clusters) | TAC(Transparent Application Continuity) | AC(Application Continuity)
 - FAN(Fast Application Notification, 장애 알림 이벤트) | FCF(Fast Connection Failover, 커넥션 풀의 빠른 장애 전환) | LTXID(Logical Transaction ID, 논리 트랜잭션 ID) | FSFO(Fast-Start Failover, Data Guard 자동 전환) | DR(Disaster Recovery, 재해 복구)

### 한줄 결론
> - RAC 는 인스턴스 장애에는 대응 가능하지만 스토리지, 데이터센터 장애에는 대응하지 못함.

## 1. 상황 설명
> - 현재 On-promise DC의 Oracle Service 를 사용중 임.
> - DB Server Instance 와 DB Storage 는 하나씩, 두개의 데이터센터에 Primary/Standby 환경구성 돼 있음. 
> - 최근 어떠한 보안 프로젝트로 인해 지속적인 Oracle DB Software Patch, DB Server - Linux 에 대한 Patch 주기가 점점 짧아지며 횟수가 증가하며 다운타임이 늘어남.
> - 이에 따라 어플리케이션 팀의 고가용성 확보가 중요해짐. (그 외에도 비즈니스 요건상 24/7 무중단 운영능력을 확보 하는것이 있었음)
> - 고가용성, High Availability AWS 의 개념상 멈추지 않고 오랜 기간동안 정상 운영되는 성질을 말함.
> - 실무에선 RAC 구성으로 DB Instance 여러개의 Resource 를 이용하여 성능을 높이기도 함. (Ex. Instance #1 과 #2에 DML 요청을 나눠서 처리하게 하기도 함)

## 2. 전체 구조

> - 계층: 앱 → 커넥션 풀 → JDBC 드라이버 → 네트워크 → 데이터베이스 서비스·리스너 → RAC 인스턴스 2개 → 공유 스토리지(데이터베이스 1개). 다른 사이트에 Data Guard Standby.

> - 장애 지점 3곳: ① 인스턴스 1 장애 ② 스토리지 장애 ③ 사이트 전체 장애
> - RAC만 있을 때 인스턴스 1이 죽으면, 그 위의 세션과 진행 중이던 트랜잭션은 어떻게 되나? 끊김. 그 후엔 앱의 로직에 따라 Transaction 이 실패 로직을 탈 것임. (FAN 에 의해 Exception 발생, 타임아웃까지 기다리지 않음)
> - 진행중이던 세션 다음의 커넥션부턴, 자동으로 인스턴스 2에 대한 커넥션 일것임. (JDBC Connection URL 에 서비스 이름으로 있어야함. FAN 에 의해 메시지를 받으면 커넥션 풀(Hikari CP)에선 인스턴스 1의 커넥션들은 다 죽이고 새로 생성. 이때 생성될때 이미 오라클 서비스는 인스턴스 2 를 바라보고 있음.)
> - ② 스토리지 장애: 예를 들어 모종의 이유로 스토리지에 IO 응답이 늦어져서 Application 에 Timeout 에러가 간헐적으로 발생하고 있는 상황이라고 한다면, RAC 는 이때 도움되지 않음.
> - ③ 사이트 전체 장애: RAC 의 인스턴스 여러개 또한 하나의 사이트에 존재하여 같은 영향을 받게 될 것임.

> **확인 / Limitation**
> - RAC는 데이터베이스 1개를 여러 인스턴스가 공유 스토리지로 함께 여는 구조다. 스토리지·사이트 장애는 막지 못한다 → DR은 Data Guard의 몫.
> - FAN이 없으면 노드·네트워크 장애 때 클라이언트가 빨리 끊기지 않아 장애 전환 자체가 늦어진다.

## 3. 핵심 판단과 근거

### 3-1. 장애가 나면 앱은 네 가지 문제를 겪는다

| 문제 | 해결하는 기능 | 앱 재시도·멱등성으로 대신되나? |
|---|---|---|
| ① 멈춤(hang) | FAN, FCF | N |
| ② 오류 처리 | AC·TAC가 오류 자체를 숨김 (없으면 앱의 몫) | Y |
| ③ 진행 중 작업의 결과: "커밋됐나?" | Transaction Guard (LTXID) | Y |
| ④ 진행 중 작업의 재제출 | AC·TAC in Data Guard | Y |

### 3-2. RAC가 하는 일과 하지 않는 일

> - 인스턴스 장애에 대응 할 수 있음
> - 스토리지/데이터센터 장애에 대응하지 못함
> - 실패한 DB Transaction 을 재처리 하지 않음 >> 이 떄는 TAC 가 등장함.

<!-- ### 3-3. TAC가 하는 일과 재실행을 포기하는 경우

> **✍️ 쓸 것**
> - TAC는 무엇을 기록하고, 장애 후 무엇을 다시 실행하나?
> - 재실행을 포기하는 경우 3가지: 커밋 이후 / 다시 실행하면 결과가 달라지는 경우 / 시간 창 초과

> **🔎 확인**
> - 서비스 속성: AC는 FAILOVER_TYPE=TRANSACTION, TAC는 AUTO(18c부터). Transaction Guard는 COMMIT_OUTCOME=TRUE.
> - 커밋으로 상태가 바뀐 뒤에는 그 트랜잭션을 재실행할 수 없다. 재실행 결과가 원래와 다르면 데이터베이스가 재실행을 거부하고 앱은 원래 오류를 받는다.
> - 시퀀스(NEXTVAL)·SYSDATE처럼 호출할 때마다 값이 바뀌는 함수는 권한(KEEP SEQUENCE, KEEP DATE TIME 등)을 줘야 재실행 때 원래 값을 쓴다.
> - 재실행 시간 창(REPLAY_INITIATION_TIMEOUT)은 서비스 속성 값이다. 문서 예시는 600초.
> - HikariCP는 6.0.0부터 요청 경계(beginRequest/endRequest)를 지원한다. 재실행에는 replay 데이터소스(oracle.jdbc.replay.OracleDataSourceImpl) 또는 통합 데이터소스(oracle.jdbc.datasource.impl.OracleDataSource)가 필요하다.
> - (선택 심화) RAC에서 시퀀스 캐시는 인스턴스마다 따로 잡혀서, NOORDER면 번호 순서가 인스턴스 사이에서 섞인다. 시퀀스 캐시를 다뤄본 경험과 이어 쓸 수 있는 지점. -->

## 4. 정리

> - RAC 구조와 각 장애 타입에 따른 RAC 가 해주는 일과 하지 못하는 일이 있다

## 참고 자료

- [Oracle 19c High Availability Overview — Configuring Level 3: Mask Unplanned and Planned Failovers from Applications](https://docs.oracle.com/en/database/oracle/oracle-database/19/haovw/configuring-level-3-mask-unplanned-and-planned-failovers-applications.html)
- [Oracle RAC Administration and Deployment Guide 21c — Ensuring Application Continuity](https://docs.oracle.com/en/database/oracle/oracle-database/21/racad/ensuring-application-continuity.html)
- [Oracle JDBC Developer's Guide 18c — Application Continuity for Java](https://docs.oracle.com/en/database/oracle/oracle-database/18/jjdbc/application-continuity.html)
- [Oracle Database Appliance — Scenario: Configuring Transparent Application Continuity](https://docs.oracle.com/en/engineered-systems/oracle-database-appliance/19.30/odadg/scenario-configuring-transparent-application-continuity.html)
- [Oracle MAA Blog — HikariCP Best Practices for Oracle Database and Spring Boot](https://blogs.oracle.com/maa/hikaricp-best-practices-for-oracle-database-and-spring-boot)
- [Oracle — Maximum Application Availability with Database 12c (2013)](https://www.oracle.com/technetwork/database/options/clustering/overview/maxappavailabilitywithdatabase12c-2008418.pdf)

<!-- ## 발행 전 체크

- [ ] ✍️·🔎 블록과 제목 후보 주석 삭제
- [ ] 기준 버전 명시 (예: 19c)
- [ ] 사내 정보 없음: 호스트명, 앱 이름, 구성 수치, 사내 시스템명
- [ ] 다이어그램 1장 첨부
- [ ] front matter의 description 채우기, draft: false로 변경 -->
